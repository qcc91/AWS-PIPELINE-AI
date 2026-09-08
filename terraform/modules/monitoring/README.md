# Monitoring foundation

Creates one complete low-volume audit chain: a dedicated customer-managed KMS
key/alias, private versioned audit bucket, retained encrypted CloudWatch log
group, CloudTrail delivery role/policy, regional management-event CloudTrail,
and one encrypted SNS topic. It creates zero subscriptions and zero alarms.

The KMS key has rotation, a 30-day deletion window, and `prevent_destroy`.
It has no account-root delegation; explicit same-account non-root admins use
management actions. CloudTrail `GenerateDataKey*` is bound to the
exact trail SourceArn/account and encryption context. CloudTrail `DescribeKey`
is a separate exact SourceArn/account grant without an encryption-context
condition, because that API call does not reliably carry the encryption
context. Logs is bound to the exact log-group encryption context; SNS is bound
to the exact topic SourceArn/account.
`Resource="*"` inside these KMS key-policy statements means the key to which
the policy is attached; service-principal grants are still constrained by the
listed SourceArn/account or encryption-context conditions.

The audit bucket uses BucketOwnerEnforced ownership, all public blocks,
versioning, default SSE-KMS, explicit current and noncurrent retention,
TLS-only access,
`force_destroy=false`, and `prevent_destroy`. CloudTrail ACL-check/write grants
are bound to the exact trail/account; writes require
`bucket-owner-full-control`. The delivery role can write only the target log
group's streams.

CloudTrail is single-region (`ap-southeast-2`), includes global service events,
records all read/write management events, and has no data resources. The
dedicated KMS key is approximately USD 1/month before request charges; S3,
CloudWatch Logs, CloudTrail management events, and SNS requests are expected to
remain low-volume. Current retention must be at least the noncurrent retention;
both values are required Human-approved inputs. Official plan-time pricing
remains required.

Identity mapping remains unresolved until the Human Owner supplies the approved
KMS administrator role ARN(s), account ID, retention choices, and eventual SNS
subscription destination. No subscription is created from an unknown endpoint.
